#!/bin/bash
#SBATCH --ntasks-per-node=4      # max MPI ranks pro Node
#SBATCH --cpus-per-task=1        # OpenMP threads per rank
#SBATCH --nodes=1
#SBATCH --time=01:00:00
#SBATCH --job-name=spectra_mpi

ml load math/Eigen/3.4.0-GCCcore-13.2.0
ml load compiler/intel-compilers/2023.2.1 mpi/impi/2021.10.0-intel-compilers-2023.2.1
# Spectra ist header-only → liegt im Repo

MPI_RANKS=(1 2 4)
SAMPLE_RATE=1
ALGORITHMS=("lanczos")

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="outputs/mpi_benchmark_$TIMESTAMP"
mkdir -p "$OUTDIR"

MATRIX="matrices/binary/bcsstk13.dat"

export OMP_NUM_THREADS=1   # Spectra ist single-threaded

for RANKS in "${MPI_RANKS[@]}"; do
    echo "--- MPI Ranks: $RANKS ---"
    
    for R in $(seq 1 $SAMPLE_RATE); do
        echo "  Run $R"

        for ALGO in "${ALGORITHMS[@]}"; do
            UPROF_RUN_DIR="$OUTDIR/${ALGO}_MPI${RANKS}_R${R}"
            mkdir -p "$UPROF_RUN_DIR"

            echo "    > Profiling Spectra $ALGO with $RANKS MPI ranks"

			mpirun -np $RANKS /home/mengelsl/amd-uprof/bin/AMDuProfCLI collect \
				--config threading \
				--mpi \
				--output-dir "$UPROF_RUN_DIR" \
				./src_c/spectra_solver "$MATRIX"
        done
    done
done

echo "DONE"