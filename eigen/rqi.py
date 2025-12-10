import numpy as np
from scipy.linalg import lu_factor, lu_solve, norm

# Load pre-saved dense matrix
A_dense = np.load("matrix_dense.npy")

# Load all eigenvectors from Lanczos
eigvecs = np.load("lanczos_top_vecs.npy")  # shape: (n, k)
k = eigvecs.shape[1]


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


# Loop over all eigenvectors
results = []
for i in range(k):
    v0 = eigvecs[:, i]
    mu, v, iters = rqi(A_dense, v0)
    results.append((mu, iters))
    print(f"RQI eigenvector {i}: refined eigenvalue {mu}, iterations {iters}")
