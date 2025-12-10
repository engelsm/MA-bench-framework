import scipy.io
import scipy.sparse as sp


def load_matrix(path):
    A = scipy.io.mmread(path)

    # Ensure CSR format for SciPy solvers/Lanczos
    if not sp.isspmatrix_csr(A):
        A = A.tocsr()

    return A
