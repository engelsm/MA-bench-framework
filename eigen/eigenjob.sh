#!/bin/bash
#SBATCH --cpus-per-task=16

module load lang/SciPy-bundle/2024.05-gfbf-2024a

# ----------------------------------------
# CONFIG
# ----------------------------------------
CORES=(1 2 4 8 16)
SAMPLE_RATE=5

# ----------------------------------------
# OUTPUT
# ----------------------------------------
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="outputs/benchmark_$TIMESTAMP"
mkdir -p "$OUTDIR"
CSV="$OUTDIR/benchmark_results.csv"

echo "cores,run,algorithm,task_duration_ms,cycles,instructions,cache_refs,cache_misses,cpu_migrations,context_switches" > "$CSV"

# ----------------------------------------
# INPUT
# ----------------------------------------
MATRIX="matrices/bcsstk13.mtx"
FORMATTED="matrices/formatted"
BASE=$(basename "$MATRIX" .mtx)
DENSE="$FORMATTED/${BASE}_dense.npy"
SPARSE="$FORMATTED/${BASE}_sparse.npz"

python3 src/load_matrix.py "$MATRIX"

# ----------------------------------------
# BENCHMARK
# ----------------------------------------
for C in "${CORES[@]}"; do
    export OMP_NUM_THREADS=$C
    echo "--- Cores: $C ---"

    for R in $(seq 1 $SAMPLE_RATE); do
        echo "  Run $R"

        LANCZOS_OUT="$OUTDIR/${BASE}_lanczos.npy"
        LOBPCG_OUT="$OUTDIR/${BASE}_lobpcg.npy"

        # -------------------------
        # LANCZOS
        # -------------------------
        PERF_LANCZOS=$(perf stat -x, \
            -e task-clock,cycles,instructions,cache-references,cache-misses,cpu-migrations,context-switches \
            python3 src/lanczos.py "$SPARSE" "$LANCZOS_OUT" \
            2>&1 >/dev/null
        )

        echo "$PERF_LANCZOS" | awk -F, -v c="$C" -v r="$R" -v a="LANCZOS" '
            /task-clock/       {td=$1}
            /cycles/           {cy=$1}
            /instructions/     {ins=$1}
            /cache-references/ {cr=$1}
            /cache-misses/     {cm=$1}
            /cpu-migrations/   {mig=$1}
            /context-switches/ {cs=$1}
            END {print c","r","a","td","cy","ins","cr","cm","mig","cs}
        ' >> "$CSV"

        # -------------------------
        # RQI
        # -------------------------
        PERF_RQI=$(perf stat -x, \
            -e task-clock,cycles,instructions,cache-references,cache-misses,cpu-migrations,context-switches \
            python3 src/rqi.py "$DENSE" "$LANCZOS_OUT" \
            2>&1 >/dev/null
        )

        echo "$PERF_RQI" | awk -F, -v c="$C" -v r="$R" -v a="RQI" '
            /task-clock/       {td=$1}
            /cycles/           {cy=$1}
            /instructions/     {ins=$1}
            /cache-references/ {cr=$1}
            /cache-misses/     {cm=$1}
            /cpu-migrations/   {mig=$1}
            /context-switches/ {cs=$1}
            END {print c","r","a","td","cy","ins","cr","cm","mig","cs}
        ' >> "$CSV"

        # -------------------------
        # LOBPCG
        # -------------------------
        PERF_LOBPCG=$(perf stat -x, \
            -e task-clock,cycles,instructions,cache-references,cache-misses,cpu-migrations,context-switches \
            python3 src/lobpcg.py "$SPARSE" "$LOBPCG_OUT" \
            2>&1 >/dev/null
        )

        echo "$PERF_LOBPCG" | awk -F, -v c="$C" -v r="$R" -v a="LOBPCG" '
            /task-clock/       {td=$1}
            /cycles/           {cy=$1}
            /instructions/     {ins=$1}
            /cache-references/ {cr=$1}
            /cache-misses/     {cm=$1}
            /cpu-migrations/   {mig=$1}
            /context-switches/ {cs=$1}
            END {print c","r","a","td","cy","ins","cr","cm","mig","cs}
        ' >> "$CSV"

    done
done

echo "DONE → $CSV"
