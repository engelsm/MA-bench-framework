import numpy as np
import scipy.sparse as sp
import scipy.sparse.linalg as spla

# Load pre-saved sparse matrix
A_sparse = sp.load_npz("matrix_sparse.npz")

# Compute top k eigenvalues/vectors using Lanczos (ARPACK)
k = 5
eigvals, eigvecs = spla.eigsh(A_sparse, k=k, which="LM")

# Save all top k eigenvectors for RQI
np.save("lanczos_top_vecs.npy", eigvecs)

# Print top eigenvalues for reference
print(f"Lanczos top {k} eigenvalues: {eigvals}")
