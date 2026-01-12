import numpy as np
import argparse
import os
import struct
from scipy.sparse import random, triu, identity, csr_matrix, diags, lil_matrix


def save_to_bin(matrix, filename):
    """Saves CSR matrix in binary format: int32(Rows, Cols, NNZ), indptr, indices, data."""
    matrix = matrix.tocsr()
    n_rows = matrix.shape[0]
    nnz = matrix.nnz

    indptr = matrix.indptr.astype(np.int32)
    indices = matrix.indices.astype(np.int32)
    data = matrix.data.astype(np.float64)

    print(
        f"Saving {filename} | N: {n_rows} | NNZ: {nnz} | Avg NNZ/Row: {nnz/n_rows:.2f}"
    )
    with open(filename, "wb") as f:
        # Header: Number of rows, columns, and non-zero elements
        f.write(struct.pack("iii", n_rows, n_rows, nnz))
        f.write(indptr.tobytes())
        f.write(indices.tobytes())
        f.write(data.tobytes())


def gen_sym_band(N, width=7):
    """1. Symmetric Band Matrix (Reference for NNZ)"""
    # NNZ per row is fixed: 2 * width + 1
    offsets = np.arange(-width, width + 1)
    data = [np.random.rand(N) for _ in offsets]
    data[width] = np.full(N, 500.0)  # Dominant diagonal for numerical stability
    return diags(data, offsets, shape=(N, N), format="csr")


def gen_sym_dist_band(N, target_nnz_row=15):
    """
    2. Symmetric Distributed Bands with NNZ Correction.
    Prevents NNZ loss at the edges by potentially adding auxiliary bands.
    """
    # 1. Calculate required number of offsets per side
    num_off_side = (target_nnz_row - 1) // 2

    # Choose offsets that are large enough for 'Dist-Band' effect but limited to prevent too much edge loss
    max_offset = min(N // 10, 5000)
    chosen_offsets = np.random.choice(
        np.arange(1, max_offset), num_off_side, replace=False
    )

    # 2. Calculate NNZ loss due to chosen offsets at the matrix boundaries
    # Each band with offset 'k' loses 2*k entries
    total_loss = sum(2 * k for k in chosen_offsets)
    # Average extra entries needed per row to compensate
    needed_extra_rows = total_loss / N

    # If loss is significant, add an extra small-offset band
    if needed_extra_rows > 1:
        extra_off = np.random.randint(1, 10)
        if extra_off not in chosen_offsets:
            chosen_offsets = np.append(chosen_offsets, extra_off)

    # 3. Assemble matrix
    offsets = np.concatenate([-chosen_offsets, [0], chosen_offsets])
    data = [np.random.rand(N - abs(off)) for off in offsets]

    # Strengthen main diagonal
    idx_diag = len(chosen_offsets)
    data[idx_diag] = np.full(N, 1000.0)

    # Use diags() with correct data lengths for respective offsets
    mat = diags(data, offsets, shape=(N, N), format="csr")

    return mat


def gen_sym_mesh(N, target_nnz_row=15):
    """
    3. Realistic Symmetric Mesh
    - Local band structure (nearest neighbors)
    - Random 'Long-Range' connections (complex geometry/clusters)
    - Maintains target NNZ budget
    """
    # 1. Base: A narrow band matrix representing local grid neighbors
    # Allocate approx 40% of the budget to local structure
    local_width = max(1, int(target_nnz_row * 0.4 // 2))
    offsets = np.arange(-local_width, local_width + 1)
    data = [np.random.rand(N) for _ in offsets]
    mat = diags(data, offsets, shape=(N, N), format="lil")

    # 2. 'Long-Range' connections (clusters outside the diagonal)
    current_nnz = mat.nnz
    target_total_nnz = N * target_nnz_row
    needed_nnz = (target_total_nnz - current_nnz) // 2  # Divide by 2 due to symmetry

    if needed_nnz > 0:
        # Generate random coordinates in 'clouds' to simulate locality
        num_clouds = 20
        nnz_per_cloud = needed_nnz // num_clouds

        for _ in range(num_clouds):
            # Center of the cloud in the upper triangle
            c_row = np.random.randint(0, int(N * 0.8))
            c_col = np.random.randint(c_row + 1, N)

            # Cloud spread (how far points scatter from center)
            spread = N // 20

            r_idx = np.random.randint(
                max(0, c_row - spread), min(N, c_row + spread), nnz_per_cloud
            )
            c_idx = np.random.randint(
                max(0, c_col - spread), min(N, c_col + spread), nnz_per_cloud
            )

            # Preserve symmetry: ensure (lower index, higher index)
            for r, c in zip(r_idx, c_idx):
                if r != c:
                    r_final, c_final = (r, c) if r < c else (c, r)
                    mat[r_final, c_final] = np.random.rand()

    # 3. Symmetrize and reinforce diagonal for numerical stability
    S = mat.tocsr()
    S = triu(S, k=1)
    final = S + S.T + identity(N) * 500.0
    return final


def gen_unsym_mesh(N, target_nnz_row=15):
    """
    4. Unsymmetric Mesh (Directed structure)
    - Same cluster structure as sym_mesh for fair comparison
    - Values and connections are NOT mirrored (A -> B != B -> A)
    """
    mat = lil_matrix((N, N))

    # 1. Local base (directed stencil)
    # Use unique random values for each diagonal to ensure asymmetry
    for off in [-2, -1, 0, 1, 2]:
        mat.setdiag(np.random.rand(N - abs(off)), k=off)

    # 2. Clusters (long-range coupling)
    target_total_nnz = N * target_nnz_row
    needed_nnz = target_total_nnz - mat.nnz

    num_clouds = 12
    if needed_nnz > 0:
        nnz_per_cloud = needed_nnz // num_clouds
        for _ in range(num_clouds):
            # Random cloud center
            c_row = np.random.randint(0, int(N * 0.7))
            c_col = np.random.randint(c_row + 1, N)
            size = max(5, N // 20)

            r_idx = np.random.randint(
                max(0, c_row - size), min(N, c_row + size), nnz_per_cloud
            )
            c_idx = np.random.randint(
                max(0, c_col - size), min(N, c_col + size), nnz_per_cloud
            )

            for r, c in zip(r_idx, c_idx):
                # Only set values at (r, c) to maintain asymmetry
                if r != c:
                    mat[r, c] = np.random.rand()

    final = mat.tocsr()
    final.setdiag(1000.0)  # Strong diagonal for solver convergence
    return final


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-N", type=int, default=10000, help="Matrix dimension")
    parser.add_argument(
        "-w", "--width", type=int, default=7, help="Half bandwidth (determines NNZ)"
    )
    parser.add_argument("-o", "--outdir", default="./matrices", help="Output directory")
    args = parser.parse_args()

    if not os.path.exists(args.outdir):
        os.makedirs(args.outdir)

    target_nnz_row = 2 * args.width + 1
    print(f"Target: ~{target_nnz_row} NNZ per row (Total: {target_nnz_row * args.N})")

    # Generation and saving
    save_to_bin(
        gen_sym_band(args.N, args.width), os.path.join(args.outdir, "sym_band.bin")
    )
    save_to_bin(
        gen_sym_dist_band(args.N, target_nnz_row),
        os.path.join(args.outdir, "sym_dist_band.bin"),
    )
    save_to_bin(
        gen_sym_mesh(args.N, target_nnz_row), os.path.join(args.outdir, "sym_mesh.bin")
    )
    save_to_bin(
        gen_unsym_mesh(args.N, target_nnz_row),
        os.path.join(args.outdir, "unsym_graph.bin"),
    )


if __name__ == "__main__":
    main()
