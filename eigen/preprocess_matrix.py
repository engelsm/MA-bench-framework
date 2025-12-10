# preprocess_matrix.py
import sys
import numpy as np
from scipy.io import mmread
import scipy.sparse as sp

if len(sys.argv) != 2:
    print("Usage: python preprocess_matrix.py matrix.mtx")
    sys.exit(1)

path = sys.argv[1]
A = mmread(path)

# Save sparse and dense versions
if sp.issparse(A):
    sp.save_npz("matrix_sparse.npz", A.tocsr())
A_dense = A.toarray() if hasattr(A, "toarray") else np.array(A)
np.save("matrix_dense.npy", A_dense)

print("Preprocessing done: matrix_sparse.npz, matrix_dense.npy created.")
