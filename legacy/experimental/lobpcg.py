import sys
import numpy as np
import scipy.sparse as sp
import scipy.sparse.linalg as spla

if len(sys.argv) != 3:
    print("Usage: python lobpcg.py <sparse_matrix.npz> <output_eigvecs.npy>")
    sys.exit(1)

matrix_file = sys.argv[1]
output_file = sys.argv[2]

# Load sparse matrix
A_sparse = sp.load_npz(matrix_file)

# Problem size
n = A_sparse.shape[0]
k = 16  # number of eigenvalues

# Initial guess (required for LOBPCG)
X = np.random.rand(n, k)

# Run LOBPCG
eigvals, eigvecs = spla.lobpcg(A_sparse, X, largest=True, tol=1e-8, maxiter=200)

# Save eigenvectors
np.save(output_file, eigvecs)

print(f"LOBPCG top {k} eigenvalues: {eigvals}")
print(f"Saved to {output_file}")
