import sys
import numpy as np
import scipy.sparse as sp
import scipy.sparse.linalg as spla

if len(sys.argv) != 3:
    print("Usage: python lanczos.py <sparse_matrix.npz> <output_eigvecs.npy>")
    sys.exit(1)

matrix_file = sys.argv[1]
output_file = sys.argv[2]

# Load sparse matrix from file
A_sparse = sp.load_npz(matrix_file)

# Compute top k eigenvalues/vectors using Lanczos (ARPACK)
k = 5
eigvals, eigvecs = spla.eigsh(A_sparse, k=k, which="LM")

# Save all top k eigenvectors to output file
np.save(output_file, eigvecs)

# Print top eigenvalues for reference
print(f"Lanczos top {k} eigenvalues: {eigvals}")
print(f"Saved eigenvectors to {output_file}")
