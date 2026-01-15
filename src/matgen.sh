#!/bin/bash
MATGEN="../build/matgen"
OUT_DIR="./visuals"
mkdir -p "$OUT_DIR"

export OMP_NUM_THREADS=$(nproc)

SEED=42
N=500               # Matrix size (N x N)
TARGET_AVG_NNZ=20   

# --- DYNAMICAL CALCULATION ---
# For symmetric matrices, the generator mirrors entries, 
# so we start with half the target to reach the full target after mirroring.
HALF_AVG=$(($TARGET_AVG_NNZ / 2))

# For the 'perfect' band matrix, we need to calculate the bandwidth (bw).
# k = bw * N  => where k is the number of neighbors on one side.
# To get TARGET_AVG_NNZ (e.g., 20), we need k = 9 (9 left + 1 center + 9 right = 19).
# Formula: bw = ( (TARGET_AVG_NNZ / 2) - 0.5 ) / N
BW_PERFECT=$(echo "scale=6; (($TARGET_AVG_NNZ / 2) - 0.5) / $N" | bc)

echo "Generating matrices with N=$N and Target NNZ/row ~ $TARGET_AVG_NNZ"
echo "Calculated perfect bandwidth: $BW_PERFECT"

# 1. PERFECT BAND (Reference)
# Mathematically exact band structure, k is derived from BW_PERFECT
$MATGEN $N 0 0 "normal" $SEED "perfect" $BW_PERFECT 0 0 0 0 "$OUT_DIR/001_perfect_band.bin"

# 2. CLUSTERED - SYMMETRIC
# Uses half avg_nnz because symmetric=1 will double it. High similarity creates blocks.
$MATGEN $N $HALF_AVG 1.0 "normal" $SEED "diagonal" 0.15 0.0 15.0 0.98 1 "$OUT_DIR/002_sym_clusters.bin"

# 3. CLUSTERED - ASYMMETRIC
# Uses full avg_nnz. Skew and Gamma distribution create load imbalance.
$MATGEN $N $TARGET_AVG_NNZ 1.0 "gamma" $SEED "diagonal" 0.15 0.8 15.0 0.98 0 "$OUT_DIR/003_asym_clusters.bin"

# 4. RANDOM - SYMMETRIC
# Uniform random placement across the whole matrix, but mirrored.
$MATGEN $N $HALF_AVG 2.0 "gamma" $SEED "random" 1.0 0.0 0.0 0.0 1 "$OUT_DIR/004_sym_random.bin"

# 5. RANDOM - ASYMMETRIC
# The ultimate stress test: no structure, no symmetry, high entropy.
$MATGEN $N $TARGET_AVG_NNZ 2.0 "normal" $SEED "random" 1.0 0.0 0.0 0.0 0 "$OUT_DIR/005_asym_random.bin"

echo "------------------------------------------------"
echo "Generation complete. Check file sizes for NNZ consistency:"
ls -lh "$OUT_DIR"

# Optionally run visualization script
# python3 visualize.py -d "$OUT_DIR" -o .