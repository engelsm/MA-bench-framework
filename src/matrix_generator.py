import numpy as np
import argparse
import struct
import os

# TODO: genauer gucken wie typische Matrizen in realen Anwendungen aussehen


def generate_matrices(N, outdir):
    bw = 20
    # 1. Preparation: Calculate NNZ and indptr for the banded (LOW) matrix
    # This NNZ value will be used as a target for all modes to ensure identical FLOPs
    row_lengths = np.zeros(N, dtype=np.int32)
    for i in range(N):
        row_lengths[i] = min(N - 1, i + bw) - max(0, i - bw) + 1

    indptr = np.zeros(N + 1, dtype=np.int32)
    indptr[1:] = np.cumsum(row_lengths)
    target_nnz = int(indptr[-1])

    # Helper function for numerically stable, symmetric values
    def get_sym_values(row_idx, col_indices):
        # Guarantee symmetry: Value depends only on min/max of indices
        v_min = np.minimum(row_idx, col_indices)
        v_max = np.maximum(row_idx, col_indices)
        dist = np.abs(row_idx - col_indices)

        # Add deterministic noise to prevent identical eigenvalues
        noise = 0.5 * np.cos(v_min * v_max * 0.1)
        vals = (1.0 / (1.0 + dist)) + noise

        # Enforce strong diagonal dominance for Lanczos stability
        # Added a slight row-dependent offset to prevent premature convergence (Early Exit)
        is_diag = row_idx == col_indices
        vals[is_diag] = 1000.0 + (row_idx % 100) * 0.1

        return vals.astype(np.float64)

    modes = ["low", "high", "med"]

    for mode in modes:
        filename = os.path.join(outdir, f"{mode}_N{N}.bin")
        cluster_size = max(1000, N // 100)

        with open(filename, "wb") as f:
            # HEADER: rows(int32), cols(int32), nnz(int32) -> "iii"
            f.write(struct.pack("iii", N, N, target_nnz))

            # Write OuterIndexPtr (indptr) - N+1 elements
            f.write(indptr.astype(np.int32).tobytes())

            # Generate and write InnerIndexPtr (indices) - nnz elements
            all_indices = []
            for i in range(N):
                if mode == "low":
                    # Structured banded pattern
                    cols = np.arange(max(0, i - bw), min(N, i + bw + 1), dtype=np.int32)
                else:
                    # Random/Clustered patterns with deterministic seeding per row
                    np.random.seed(i)
                    count = indptr[i + 1] - indptr[i]
                    if mode == "high":
                        # Fully random distribution (Stress for L3/DRAM)
                        cols = np.random.randint(0, N, size=count, dtype=np.int32)
                    else:  # med
                        # 90% Cluster probability
                        mask = np.random.rand(count) < 0.90
                        cluster_start = (i // cluster_size) * cluster_size
                        glob = np.random.randint(0, N, size=count)
                        clust = cluster_start + np.random.randint(
                            0, cluster_size, size=count
                        )
                        cols = np.where(mask, clust, glob) % N

                    # CSR requires sorted indices per row for optimal SpMV performance
                    cols = np.sort(cols.astype(np.int32))

                f.write(cols.tobytes())
                # Temporarily store indices for the second pass (Value generation)
                all_indices.append(cols)

            # Generate and write ValuePtr (values) - nnz elements
            for i in range(N):
                cols = all_indices[i]
                vals = get_sym_values(i, cols)
                f.write(vals.astype(np.float64).tobytes())

        print(f"{mode.upper()} done: {filename}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate symmetric CSR matrices.")
    parser.add_argument("-n", type=int, required=True, help="Matrix dimension N")
    parser.add_argument(
        "--outdir", type=str, required=True, help="Output directory for binary files"
    )
    args = parser.parse_args()

    if not os.path.exists(args.outdir):
        os.makedirs(args.outdir)

    generate_matrices(args.n, args.outdir)
