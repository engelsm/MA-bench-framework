import sys
import numpy as np
from scipy.linalg import lu_factor, lu_solve, norm


def rqi(A, v0, maxit=20, tol=1e-12):
    v = v0 / norm(v0)
    for i in range(maxit):
        mu = float(v.T @ (A @ v))
        M = A - mu * np.eye(A.shape[0])
        lu, piv = lu_factor(M)
        w = lu_solve((lu, piv), v)
        v = w / norm(w)
        res = norm(A @ v - mu * v)
        if res < tol:
            return mu, v, i + 1
    return mu, v, maxit


def rqi_all(A, eigvecs, maxit=20, tol=1e-12):
    k = eigvecs.shape[1]
    results = []
    for i in range(k):
        v0 = eigvecs[:, i]
        mu, v, iters = rqi(A, v0, maxit=maxit, tol=tol)
        results.append((mu, v, iters))
        print(f"RQI eigenvector {i}: refined eigenvalue {mu}, iterations {iters}")
    return results


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python rqi.py <dense_matrix.npy> <eigenvectors.npy>")
        sys.exit(1)

    matrix_file = sys.argv[1]
    eigenvec_file = sys.argv[2]

    A_dense = np.load(matrix_file)
    eigvecs = np.load(eigenvec_file)

    rqi_all(A_dense, eigvecs)
