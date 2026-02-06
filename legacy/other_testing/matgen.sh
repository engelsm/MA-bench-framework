#!/bin/bash
# Path to the matrix generator executable
MATGEN="../build/matgen"
# Directory where the generated matrices will be stored
BASE_DIR="../matrices/cgen"
mkdir -p "$BASE_DIR"

# Seed for reproducibility across platforms
SEED=42
# Target average Non-Zeros per row across all matrices
TARGET_AVG_NNZ=30

# Matrix sizes (N x N)
# N=20000   -> ~5MB   (Fits comfortably in L3 of a few CCDs)
# N=200000  -> ~50MB  (Exceeds single CCD L3, fits in NUMA node L3)
# N=2000000 -> ~500MB (Exceeds total L3 of 48 cores, pure RAM test)
SIZES=(20000 200000 2000000)

for N in "${SIZES[@]}"; do
    # Create subdirectories for each size to keep the pool organized
    OUT_DIR="$BASE_DIR/size_$N"
    mkdir -p "$OUT_DIR"
    
    # Calculate values for symmetry and perfect band logic
    HALF_AVG=$(($TARGET_AVG_NNZ / 2))
    # BW_PERFECT ensures k neighbors on each side to reach TARGET_AVG_NNZ
    BW_PERFECT=$(echo "scale=6; (($TARGET_AVG_NNZ / 2) - 0.5) / $N" | bc)

    echo "--- Generating matrices for N=$N ---"

    # 1. PERFECT BAND (Deterministic/Reference)
    # Provides the baseline for maximum hardware prefetcher efficiency
    $MATGEN $N 0 0 "normal" $SEED "perfect" $BW_PERFECT 0 0 0 0 "$OUT_DIR/001_perfect_band.bin"

    # 2. CLUSTERED - SYMMETRIC
    # High similarity (0.98) and neighbors (15) create localized dense blocks
    $MATGEN $N $HALF_AVG 1.0 "normal" $SEED "diagonal" 0.15 0.0 15.0 0.98 1 "$OUT_DIR/002_sym_clusters.bin"

    # 3. CLUSTERED - ASYMMETRIC
    # Skew (0.8) and Gamma distribution create row-length imbalance (load imbalance)
    $MATGEN $N $TARGET_AVG_NNZ 1.0 "gamma" $SEED "diagonal" 0.15 0.8 15.0 0.98 0 "$OUT_DIR/003_asym_clusters.bin"

    # 4. RANDOM - SYMMETRIC
    # Spreads entries across the whole bandwidth (1.0), stressing the TLB and cache
    $MATGEN $N $HALF_AVG 2.0 "gamma" $SEED "random" 1.0 0.0 0.0 0.0 1 "$OUT_DIR/004_sym_random.bin"

    # 5. RANDOM - ASYMMETRIC
    # Maximum entropy: No symmetry, no spatial locality, unpredictable access patterns
    $MATGEN $N $TARGET_AVG_NNZ 2.0 "normal" $SEED "random" 1.0 0.0 0.0 0.0 0 "$OUT_DIR/005_asym_random.bin"
done

echo "------------------------------------------------"
echo "Workload generation finished in $BASE_DIR"
du -sh "$BASE_DIR"/*