import sys
import numpy as np
import scipy.sparse as sp
import scipy.sparse.linalg as spla

if len(sys.argv) != 3:
    print("Usage: python lanczos.py <sparse_matrix.npz> <output_eigvecs.npy>")
    sys.exit(1)

matrix_file = sys.argv[1]
output_file = sys.argv[2]

A_sparse = sp.load_npz(matrix_file)

k = 2  # num eigenvalues
eigvals, eigvecs = spla.eigsh(A_sparse, k=k, which="LM")

np.save(output_file, eigvecs)

print(f"Lanczos top {k} eigenvalues: {eigvals}")
print(f"Saved to {output_file}")
