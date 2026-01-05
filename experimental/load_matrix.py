import sys
import os
import numpy as np
from scipy.io import mmread
import scipy.sparse as sp

if len(sys.argv) != 2:
    print("Usage: python load_matrix.py <matrix.mtx>")
    sys.exit(1)

matrix_path = sys.argv[1]
matrix_name = os.path.splitext(os.path.basename(matrix_path))[0]

formatted_dir = os.path.join(os.path.dirname(matrix_path), "formatted")
os.makedirs(formatted_dir, exist_ok=True)

# Load matrix
A = mmread(matrix_path)

# Save sparse and dense versions
if sp.issparse(A):
    sp.save_npz(os.path.join(formatted_dir, f"{matrix_name}_sparse.npz"), A.tocsr())
A_dense = A.toarray() if hasattr(A, "toarray") else np.array(A)
np.save(os.path.join(formatted_dir, f"{matrix_name}_dense.npy"), A_dense)
