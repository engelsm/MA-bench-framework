import numpy as np
import scipy.sparse as sp
import scipy.sparse.linalg as spla
from scipy.linalg import lu_factor, lu_solve, norm
import time

# LAPACK optimized operations dominate runtime thus python overhead is minimal


# Compute-bound
def rayleigh_quotient_iteration(A, v0, maxit=10, tol=1e-12):
    n = A.shape[0]
    v = v0 / norm(v0)
    for k in range(maxit):
        mu = v.T @ (A @ v)
        M = A - mu * np.eye(n)
        lu, piv = lu_factor(M, overwrite_a=True)
        w = lu_solve((lu, piv), v)
        v = w / norm(w)
        res = norm(A @ v - mu * v)
        if res < tol:
            return mu, v, k + 1
    return mu, v, maxit


# Memory-bound
def lanczos(A_sparse, k=5, ncv=None):
    eigvals, eigvecs = spla.eigsh(A_sparse, k=k, which="LM", ncv=ncv)
    return eigvals, eigvecs


n = 500  # Matrix size
# Sparse 1D Laplacian
diagonals = [-1 * np.ones(n - 1), 2 * np.ones(n), -1 * np.ones(n - 1)]
A_sparse = sp.diags(diagonals, [-1, 0, 1], format="csr")

# Für RQI dense Umwandlung
A_dense = A_sparse.toarray()

# Hybrid workflow: Lanczos + RQI refinement
print("Running Lanczos (memory-bound, sparse)...")
start = time.time()
eigvals_approx, eigvecs_approx = lanczos(A_sparse, k=5)
end = time.time()
print(f"Lanczos top 5 eigenvalues (approx): {eigvals_approx}")
print(f"Time taken: {end-start:.3f}s\n")

print("Refining with RQI (compute-bound, dense)...")
refined_eigvals = []
rqi_times = []
for i in range(eigvecs_approx.shape[1]):
    v0 = eigvecs_approx[:, i]
    start = time.time()
    mu, v, iters = rayleigh_quotient_iteration(A_dense, v0, maxit=5)
    end = time.time()
    refined_eigvals.append(mu)
    rqi_times.append(end - start)
    print(
        f"Eigenvalue {i+1}: refined ~ {mu:.6f}, iterations={iters}, time={end-start:.3f}s"
    )

print("\nAll refined eigenvalues:", refined_eigvals)
print("RQI refinement times per eigenvalue:", rqi_times)
