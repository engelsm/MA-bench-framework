import sys
import numpy as np
from scipy.linalg import lu_factor, lu_solve, norm


def rqi(A, v0, maxit=20, tol=1e-12):
    v = v0 / norm(v0)  # Start vector
    for i in range(maxit):
        mu = float(
            v.T @ (A @ v)
        )  # Simplified Rayleigh quotient because v is normalized, mu is approximate eigenvalue of eigenvector v
        M = A - mu * np.eye(A.shape[0])  # Shifted matrix
        lu, piv = lu_factor(
            M
        )  # In this and the next line, we solve M*w = v <=> w = M^{-1}*v with LU
        w = lu_solve(
            (lu, piv), v
        )  # w is a better approximation of the eigenvector of A (and M and M^{-1} as they all share eigenvectors)
        v = w / norm(w)  # Normalize
        res = norm(A @ v - mu * v)  # Residual
        if res < tol:  # Convergence check
            return mu, v, i + 1
    return mu, v, maxit


def rqi_all(A, eigvecs):
    k = eigvecs.shape[1]
    results = []
    for i in range(k):
        v0 = eigvecs[:, i]
        mu, v, iters = rqi(A, v0)
        results.append((mu, v, iters))
        print(f"RQI eigenvector {i}: refined eigenvalue {mu}, iterations {iters}")
    return results


if len(sys.argv) != 3:
    print("Usage: python rqi.py <dense_matrix.npy> <lanczos_eigenvectors.npy>")
    sys.exit(1)

A_dense = np.load(sys.argv[1])
eigvecs = np.load(sys.argv[2])

rqi_all(A_dense, eigvecs)
